-- ============================================================
-- ARQUITETURA DE BANCO DE DADOS - GABRIELLY MAKEUP (SUPABASE)
-- ============================================================

-- 1. TABELA DE HORÁRIOS DE ATENDIMENTO PADRÃO (BUSINESS HOURS)
CREATE TABLE IF NOT EXISTS public.business_hours (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    day_of_week INT NOT NULL CHECK (day_of_week BETWEEN 0 AND 6), -- 0=Domingo, 1=Segunda ... 6=Sábado
    start_time TIME NOT NULL DEFAULT '08:00:00',
    end_time TIME NOT NULL DEFAULT '19:00:00',
    slot_duration_minutes INT NOT NULL DEFAULT 60,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(day_of_week)
);

-- Inserir / Atualizar horários de funcionamento: TODOS OS DIAS das 08:00 às 20:00
INSERT INTO public.business_hours (day_of_week, start_time, end_time, slot_duration_minutes, is_active)
VALUES 
    (0, '08:00', '20:00', 60, true), -- Domingo
    (1, '08:00', '20:00', 60, true), -- Segunda
    (2, '08:00', '20:00', 60, true), -- Terça
    (3, '08:00', '20:00', 60, true), -- Quarta
    (4, '08:00', '20:00', 60, true), -- Quinta
    (5, '08:00', '20:00', 60, true), -- Sexta
    (6, '08:00', '20:00', 60, true)  -- Sábado
ON CONFLICT (day_of_week) DO UPDATE SET 
    start_time = EXCLUDED.start_time,
    end_time = EXCLUDED.end_time,
    is_active = EXCLUDED.is_active;


-- 2. TABELA DE DIAS BLOQUEADOS (FOLGAS / FERIADOS / EXCEÇÕES)
CREATE TABLE IF NOT EXISTS public.blocked_dates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    blocked_date DATE NOT NULL UNIQUE,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- 3. TABELA DE AGENDAMENTOS (APPOINTMENTS)
CREATE TABLE IF NOT EXISTS public.appointments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_name TEXT NOT NULL,
    customer_phone TEXT NOT NULL,
    service TEXT NOT NULL,
    appointment_date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    location_type TEXT NOT NULL DEFAULT 'estudio',
    status TEXT NOT NULL DEFAULT 'confirmed' CHECK (status IN ('confirmed', 'cancelled', 'completed')),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- PREVENÇÃO ABSOLUTA DE DUPLO AGENDAMENTO NO POSTGRESQL (ÍNDICE ÚNICO CONDICIONAL)
-- Garante que NUNCA existirão dois agendamentos ativos na mesma data e horário
CREATE UNIQUE INDEX IF NOT EXISTS unique_active_appointment_slot 
ON public.appointments (appointment_date, start_time) 
WHERE (status != 'cancelled');


-- 4. FUNÇÃO TRIGGER PARA ATUALIZAR 'updated_at'
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_appointments_updated_at ON public.appointments;
CREATE TRIGGER set_appointments_updated_at
BEFORE UPDATE ON public.appointments
FOR EACH ROW
EXECUTE FUNCTION public.handle_updated_at();


-- ============================================================
-- POLÍTICAS DE SEGURANÇA (ROW LEVEL SECURITY - RLS)
-- ============================================================

ALTER TABLE public.business_hours ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.blocked_dates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;

-- Business Hours: Público pode ler horários, Admin pode editar
CREATE POLICY "Public can view business hours" 
ON public.business_hours FOR SELECT 
TO public USING (true);

CREATE POLICY "Admin can manage business hours" 
ON public.business_hours FOR ALL 
TO authenticated USING (true) WITH CHECK (true);


-- Blocked Dates: Público pode ver quais dias estão bloqueados, Admin gerencia
CREATE POLICY "Public can view blocked dates" 
ON public.blocked_dates FOR SELECT 
TO public USING (true);

CREATE POLICY "Admin can manage blocked dates" 
ON public.blocked_dates FOR ALL 
TO authenticated USING (true) WITH CHECK (true);


-- Appointments:
-- Público (anon) pode apenas CRIAR agendamentos válidos
CREATE POLICY "Public can insert appointment" 
ON public.appointments FOR INSERT 
TO public WITH CHECK (
    customer_name IS NOT NULL AND 
    customer_phone IS NOT NULL AND 
    appointment_date >= CURRENT_DATE
);

-- Admin (authenticated) pode ler, atualizar e gerenciar todos os agendamentos
CREATE POLICY "Admin can view all appointments" 
ON public.appointments FOR SELECT 
TO authenticated USING (true);

CREATE POLICY "Admin can update appointments" 
ON public.appointments FOR UPDATE 
TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Admin can delete appointments" 
ON public.appointments FOR DELETE 
TO authenticated USING (true);


-- ============================================================
-- FUNÇÃO RPC PARA PRIVACIDADE TOTAL DOS CLIENTES
-- Retorna apenas os horários e se estão disponíveis/ocupados/bloqueados
-- SEM EXPOR NENHUM DADO PESSOAL DE OUTROS CLIENTES
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_public_slots(target_date DATE)
RETURNS TABLE (
    slot_time TIME,
    slot_status TEXT -- 'available' | 'booked' | 'blocked'
) 
SECURITY DEFINER
LANGUAGE plpgsql
AS $$
DECLARE
    v_dow INT;
    v_start TIME;
    v_end TIME;
    v_step INT;
    v_is_active BOOLEAN;
    v_is_blocked BOOLEAN;
    curr_time TIME;
BEGIN
    -- 1. Verificar se a data está na tabela de datas bloqueadas
    SELECT EXISTS (SELECT 1 FROM public.blocked_dates WHERE blocked_date = target_date) INTO v_is_blocked;
    IF v_is_blocked THEN
        RETURN;
    END IF;

    -- 2. Obter dia da semana (0=Dom ... 6=Sáb)
    v_dow := EXTRACT(DOW FROM target_date);

    -- 3. Obter configuração do dia
    SELECT start_time, end_time, slot_duration_minutes, is_active 
    INTO v_start, v_end, v_step, v_is_active
    FROM public.business_hours 
    WHERE day_of_week = v_dow;

    -- Se o dia não estiver ativo ou não configurado, retorna vazio
    IF v_is_active IS NOT TRUE OR v_start IS NULL OR v_end IS NULL THEN
        RETURN;
    END IF;

    -- 4. Gerar slots de tempo
    curr_time := v_start;
    WHILE curr_time < v_end LOOP
        IF EXISTS (
            SELECT 1 FROM public.appointments 
            WHERE appointment_date = target_date 
              AND start_time = curr_time 
              AND status != 'cancelled'
        ) THEN
            slot_time := curr_time;
            slot_status := 'booked';
            RETURN NEXT;
        ELSE
            slot_time := curr_time;
            slot_status := 'available';
            RETURN NEXT;
        END IF;

        curr_time := curr_time + (v_step || ' minutes')::INTERVAL;
    END LOOP;
END;
$$;
